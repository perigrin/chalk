# ABOUTME: Library code for the y/yd probes (third final audit, 2026-11-25):
# ABOUTME: a followed module whose subs localize its package scalar.
package YLocal;
our $lv = 1; sub with { local $lv = 2; inner() } sub inner { $lv } sub set { $lv = $_[0]; return }
1;
