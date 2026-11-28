package O; my $x = 1; sub new { bless {}, shift } sub lv :lvalue { $x } sub set { $x = $_[1]; 0 } package main; my $o = O->new; my @l = ($o->lv, $o->set(5)); print "@l\n";
