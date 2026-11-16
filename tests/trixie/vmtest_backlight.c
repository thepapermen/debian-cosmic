// SPDX-License-Identifier: GPL-2.0
/*
 * Laptop backlights for the VM tests (hardware.sh), which QEMU does not have:
 *
 * - "vmtest::kbd_backlight", a keyboard backlight LED (levels 0-3). UPower
 *   finds it by its name. A laptop's own key changes it in the firmware and
 *   the kernel tells (brightness_hw_changed); writing a level to
 *   /sys/module/vmtest_backlight/parameters/kbd_hw does the same.
 * - "vmtest_backlight", a screen backlight for the brightness keys and the
 *   slider: the desktop sets it through logind. Its levels (bl_max, default
 *   0-100) and type (bl_type: raw, platform or firmware) are module
 *   parameters, as is a second one, "vmtest_backlight2" (bl2_max, bl2_type;
 *   none unless bl2_max is set), as some laptops have. A panel that stays
 *   dark at its lowest levels (an OLED, or a backlight that only lights up
 *   above a threshold) is bl_dark: up to that level actual_brightness reads 0.
 *   Writing a level to /sys/module/vmtest_backlight/parameters/bl_hw sets the
 *   screen backlight as a laptop's firmware does on its brightness key, and
 *   tells (a uevent, as backlight_force_update does for ACPI hotkeys).
 *
 * Built and loaded in the guest for the test only; nothing reads hardware.
 */
#include <linux/backlight.h>
#include <linux/leds.h>
#include <linux/module.h>
#include <linux/platform_device.h>

static struct platform_device *pdev;
static struct backlight_device *bl;
static enum led_brightness kbd_level;

static void kbd_set(struct led_classdev *cdev, enum led_brightness value)
{
	kbd_level = value;
}

static enum led_brightness kbd_get(struct led_classdev *cdev)
{
	return kbd_level;
}

static struct led_classdev kbd = {
	.name = "vmtest::kbd_backlight",
	.max_brightness = 3,
	.flags = LED_BRIGHT_HW_CHANGED,
	.brightness_set = kbd_set,
	.brightness_get = kbd_get,
};

/* kbd_hw: as if the laptop's key had set the keyboard backlight. */
static int kbd_hw_set(const char *val, const struct kernel_param *kp)
{
	unsigned int level;
	int ret = kstrtouint(val, 10, &level);

	if (ret)
		return ret;
	if (level > kbd.max_brightness)
		return -EINVAL;
	kbd_level = level;
	kbd.brightness = level;
	led_classdev_notify_brightness_hw_changed(&kbd, level);
	return 0;
}

static int kbd_hw_get(char *buf, const struct kernel_param *kp)
{
	return sysfs_emit(buf, "%u\n", kbd_level);
}

static const struct kernel_param_ops kbd_hw_ops = {
	.set = kbd_hw_set,
	.get = kbd_hw_get,
};
module_param_cb(kbd_hw, &kbd_hw_ops, NULL, 0644);
MODULE_PARM_DESC(kbd_hw, "set the keyboard backlight as the hardware would");

static struct backlight_device *bl2;
static unsigned int bl_max = 100, bl2_max, bl_dark;
static char *bl_type = "raw", *bl2_type = "raw";
module_param(bl_max, uint, 0444);
MODULE_PARM_DESC(bl_max, "screen backlight levels: 0 to bl_max (default 100)");
module_param(bl_type, charp, 0444);
MODULE_PARM_DESC(bl_type, "screen backlight type: raw (default), platform or firmware");
module_param(bl2_max, uint, 0444);
MODULE_PARM_DESC(bl2_max, "a second screen backlight with these levels (default none)");
module_param(bl2_type, charp, 0444);
MODULE_PARM_DESC(bl2_type, "the second one's type");
module_param(bl_dark, uint, 0444);
MODULE_PARM_DESC(bl_dark, "levels up to this one leave the panel dark (actual_brightness 0)");

static int bl_update(struct backlight_device *bd)
{
	return 0;                       /* nothing to drive */
}

static int bl_get(struct backlight_device *bd)
{
	int level = backlight_get_brightness(bd);

	return bd == bl && level <= bl_dark ? 0 : level;
}

static const struct backlight_ops bl_ops = {
	.update_status = bl_update,
	.get_brightness = bl_get,
};

/* bl_hw: as if the laptop's firmware had changed the screen backlight. */
static int bl_hw_set(const char *val, const struct kernel_param *kp)
{
	unsigned int level;
	int ret = kstrtouint(val, 10, &level);

	if (ret)
		return ret;
	if (!bl || level > bl->props.max_brightness)
		return -EINVAL;
	bl->props.brightness = level;
	backlight_force_update(bl, BACKLIGHT_UPDATE_HOTKEY);
	return 0;
}

static int bl_hw_get(char *buf, const struct kernel_param *kp)
{
	return sysfs_emit(buf, "%d\n", bl ? bl->props.brightness : -1);
}

static const struct kernel_param_ops bl_hw_ops = {
	.set = bl_hw_set,
	.get = bl_hw_get,
};
module_param_cb(bl_hw, &bl_hw_ops, NULL, 0644);
MODULE_PARM_DESC(bl_hw, "set the screen backlight as the firmware would");

static int bl_type_of(const char *name, enum backlight_type *type)
{
	if (!strcmp(name, "raw"))
		*type = BACKLIGHT_RAW;
	else if (!strcmp(name, "platform"))
		*type = BACKLIGHT_PLATFORM;
	else if (!strcmp(name, "firmware"))
		*type = BACKLIGHT_FIRMWARE;
	else
		return -EINVAL;
	return 0;
}

static struct backlight_device *bl_register(const char *name, unsigned int max, const char *type)
{
	struct backlight_properties props = {
		.max_brightness = max,
		.brightness = max,
	};
	int ret = bl_type_of(type, &props.type);

	if (ret)
		return ERR_PTR(ret);
	if (!max)
		return ERR_PTR(-EINVAL);
	return backlight_device_register(name, &pdev->dev, NULL, &bl_ops, &props);
}

static int __init vmtest_init(void)
{
	int ret;

	pdev = platform_device_register_simple("vmtest-backlight", -1, NULL, 0);
	if (IS_ERR(pdev))
		return PTR_ERR(pdev);
	ret = led_classdev_register(&pdev->dev, &kbd);
	if (ret)
		goto out_pdev;
	bl = bl_register("vmtest_backlight", bl_max, bl_type);
	if (IS_ERR(bl)) {
		ret = PTR_ERR(bl);
		bl = NULL;
		goto out_led;
	}
	if (bl2_max) {
		bl2 = bl_register("vmtest_backlight2", bl2_max, bl2_type);
		if (IS_ERR(bl2)) {
			ret = PTR_ERR(bl2);
			bl2 = NULL;
			goto out_bl;
		}
	}
	return 0;
out_bl:
	backlight_device_unregister(bl);
out_led:
	led_classdev_unregister(&kbd);
out_pdev:
	platform_device_unregister(pdev);
	return ret;
}

static void __exit vmtest_exit(void)
{
	if (bl2)
		backlight_device_unregister(bl2);
	backlight_device_unregister(bl);
	led_classdev_unregister(&kbd);
	platform_device_unregister(pdev);
}

module_init(vmtest_init);
module_exit(vmtest_exit);
MODULE_DESCRIPTION("Simulated laptop backlights for VM tests");
MODULE_LICENSE("GPL");
