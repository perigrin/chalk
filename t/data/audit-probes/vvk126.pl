package C; sub new { my ($c, %a) = @_; bless {n => 0, %a}, $c } sub inc { $_[0]{n}++; $_[0] } sub n { $_[0]{n} } package main; my $o = C->new(n => 5); $o->inc->inc; print $o->n, "\n";
