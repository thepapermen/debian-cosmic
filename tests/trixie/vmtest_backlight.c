// SPDX-License-Identifier: GPL-2.0
/*
 * Laptop backlights for the VM tests (hardware.sh), which QEMU does not have:
 *
 * - "vmtest::kbd_backlight", a keyboard backlight LED (levels 0-3). UPower
 *   finds it by its name. A laptop's own key changes it in the firmware and
 *   the kernel tells (brightness_hw_changed); writing a level to
 *   /sys/module/vmtest_backlight/parameters/kbd_hw does the same.
 * - "vmtest_backlight", a screen backlight (raw, 0-100), for the brightness
 *   keys and the slider: the desktop sets it through logind.
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

static int bl_update(struct backlight_device *bd)
{
	return 0;                       /* nothing to drive */
}

static const struct backlight_ops bl_ops = {
	.update_status = bl_update,
};

static int __init vmtest_init(void)
{
	struct backlight_properties props = {
		.type = BACKLIGHT_RAW,
		.max_brightness = 100,
		.brightness = 100,
	};
	int ret;

	pdev = platform_device_register_simple("vmtest-backlight", -1, NULL, 0);
	if (IS_ERR(pdev))
		return PTR_ERR(pdev);
	ret = led_classdev_register(&pdev->dev, &kbd);
	if (ret)
		goto out_pdev;
	bl = backlight_device_register("vmtest_backlight", &pdev->dev, NULL, &bl_ops, &props);
	if (IS_ERR(bl)) {
		ret = PTR_ERR(bl);
		goto out_led;
	}
	return 0;
out_led:
	led_classdev_unregister(&kbd);
out_pdev:
	platform_device_unregister(pdev);
	return ret;
}

static void __exit vmtest_exit(void)
{
	backlight_device_unregister(bl);
	led_classdev_unregister(&kbd);
	platform_device_unregister(pdev);
}

module_init(vmtest_init);
module_exit(vmtest_exit);
MODULE_DESCRIPTION("Simulated laptop backlights for VM tests");
MODULE_LICENSE("GPL");
