#include "core.h"

int ko_init(void) {
	pr_info("Shamiko init");
	return 0;
}

void ko_exit(void){
	pr_info("Shamiko exit");
}

module_init(ko_init);
module_exit(ko_exit);
MODULE_LICENSE("GPL");
MODULE_AUTHOR("Ylarod");
MODULE_DESCRIPTION("Shamiko in Kernel");
MODULE_IMPORT_NS(VFS_internal_I_am_really_a_filesystem_and_am_NOT_a_driver);