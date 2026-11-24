package C; sub new { bless {v=>1}, shift } sub a { $_[0]{v}=5 } sub b { $_[0]{v} } package main; my $o=C->new; my $m="a"; my $x=$o->{v}; $o->$m; print $x, $o->b, "\n";
