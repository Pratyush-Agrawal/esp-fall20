#ifndef _CHOLESKY_H_
#define _CHOLESKY_H_

#ifdef __KERNEL__
#include <linux/ioctl.h>
#include <linux/types.h>
#else
#include <sys/ioctl.h>
#include <stdint.h>
#ifndef __user
#define __user
#endif
#endif /* __KERNEL__ */

#include <esp.h>
#include <esp_accelerator.h>

struct cholesky_access {
	struct esp_access esp;
	/* <<--regs-->> */
	unsigned input_rows;
	unsigned output_rows;
	unsigned src_offset;
	unsigned dst_offset;
};

#define CHOLESKY_IOC_ACCESS	_IOW ('S', 0, struct cholesky_access)

#endif /* _CHOLESKY_H_ */
