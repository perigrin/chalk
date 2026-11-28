sub cm { my @f = @_; sub { my $v = shift; $v = $_->($v) for @f; $v } } print cm(sub { $_[0] + 1 }, sub { $_[0] * 2 })->(3), "\n";
