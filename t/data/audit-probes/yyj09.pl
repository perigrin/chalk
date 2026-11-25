sub apply { my ($f, @l) = @_; map { $f->($_) } @l } print join(",", apply(sub { $_[0] * 2 }, 1,2,3)), "\n";
