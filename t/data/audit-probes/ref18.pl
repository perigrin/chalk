my $x=1; my $f=sub { my $o=$x; $x=$_[0]; $o }; my @l = map { $f->($_) } 5,6; print "@l $x\n";
