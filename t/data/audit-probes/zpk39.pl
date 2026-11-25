sub f { $_="c" } $_="a"; my $o=$_; f(); print "$o$_\n";
