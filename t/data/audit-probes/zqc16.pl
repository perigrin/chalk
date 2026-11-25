package C; my @a=(1,2); sub new { bless {}, shift } sub z { $a[1]=7 } package main; my $o=C->new; for my $x (@a) { $o->z; print $x } print "\n";
