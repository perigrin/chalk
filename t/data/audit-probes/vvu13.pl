package O; sub new { bless { n => 1 }, shift } sub n { $_[0]{n} } sub set { $_[0]{n} = $_[1]; 0 } package main; my $o = O->new; my $m = "n"; my @l = ($o->$m, $o->set(5)); print "@l ", $o->$m, "\n";
