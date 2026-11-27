package O; sub new { bless [], shift } sub m { $_[0] = "gone"; ref $_[0] } package main; my $o = O->new; my $r = $o->m; print $r, ref($o) ? "ref" : $o, "\n";
