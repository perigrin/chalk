sub apply { my ($f, @r) = @_; return map { $f->($_) } @r } print join(",", apply(sub { $_[0] * 2 }, 1, 2, 3)), "\n";
