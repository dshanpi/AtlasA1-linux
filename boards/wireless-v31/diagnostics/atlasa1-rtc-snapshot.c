#include <linux/module.h>
#include <linux/io.h>
static int __init snap(void)
{
 void __iomem *p=ioremap(0x07090000,0x180);
 static const unsigned int offs[]={0,4,0x60,0x160,0x16c};
 unsigned int i;
 if(!p)return -ENOMEM;
 for(i=0;i<ARRAY_SIZE(offs);i++) pr_info("atlas-rtc-snapshot %08x=%08x\n",0x07090000+offs[i],readl(p+offs[i]));
 iounmap(p);
 return 0;
}
static void __exit done(void){}
module_init(snap);module_exit(done);MODULE_LICENSE("GPL");
