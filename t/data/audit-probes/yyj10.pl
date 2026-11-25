sub compose { my @f = reverse @_; sub { my @a = @_; @a = $_->(@a) for @f; wantarray ? @a : $a[0] } } my $h = compose(sub { $_[0] + 1 }, sub { $_[0] * 2 }); print $h->(5), "\n";
