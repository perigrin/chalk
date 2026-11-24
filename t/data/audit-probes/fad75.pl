our $g=1; sub f { local $g=2; my @a=(1,2); my $i=$_[0]; local $a[$i]=5; die "x\n" } eval { f(0) }; print "$g\n";
