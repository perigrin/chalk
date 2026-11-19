our $g = 0; package O; sub new { bless {}, shift } sub hit { $main::g += 10 } package main; my $o = O->new; for my $i (1..3) { $g = $g + 1; $o->hit; } print "$g\n";
