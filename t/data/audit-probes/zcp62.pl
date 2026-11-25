my @a=(1,2); sub mk { my @l=@_; sub { "@l" } } my $c=mk(@a); $a[0]=9; print $c->(), "\n";
