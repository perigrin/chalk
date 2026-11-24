package C; sub new { bless {n=>1}, shift } sub sw { $_[0] = C->new; $_[0]{n}=2 } package main; my $o=C->new; my $p=$o; $o->sw; print $o->{n}, $p->{n}, "\n";
