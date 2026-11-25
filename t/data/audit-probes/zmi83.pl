my @subs=map { my $n=$_; sub { $n*$_[0] } } 1..3; print join(",", map { $_->(10) } @subs), "\n";
