my $acc=""; my $f=sub { $acc.=$_[0]; $acc }; my $r1=$f->("a"); my $r2=$f->("b"); print "$r1 $r2 $acc\n";
