package C; sub new { bless {n=>0}, shift } sub inc { $_[0]{n}++; die "x\n" if $_[0]{n}>1; } package main; my $o=C->new; eval { $o->inc; $o->inc; $o->inc }; print $o->{n},"\n";
