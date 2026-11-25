# ABOUTME: Library code for the y/yd probes (third final audit, 2026-11-25):
# ABOUTME: a followed module whose import stores into the program's package and its own.
package YImp;
our $cnt = 0; sub import { $cnt++; $main::imp .= "i"; return } sub cnt { $cnt }
1;
