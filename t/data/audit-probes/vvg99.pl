sub ap { my ($f, @a) = @_; map { $f->($_) } @a } my $k = 2; print join(",", ap(sub { $_[0] * $k }, 1, 2)), "\n";
