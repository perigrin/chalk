# ABOUTME: Library code for the y/yd probes (third final audit, 2026-11-25):
# ABOUTME: a followed module whose package variables hold references that share storage.
package YRef;
our @l = (1); our $r = \@l; our $p = [1]; our $q = $p; our $n = 1; our $sr = \$n;
our $nest = { l => [ 1, 2 ], h => { c => 3 } }; our %h = (a => [1]); our $ha = $h{a};
sub lstr { "@l" } sub nval { $n }
1;
