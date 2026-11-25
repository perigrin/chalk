# ABOUTME: Library code for the y/yd probes (third final audit, 2026-11-25):
# ABOUTME: a followed module whose file-level code reads another followed module.
package YTwo;
use YInit; our $m = $YInit::n + 10; YInit::bump(); sub m { $m }
1;
