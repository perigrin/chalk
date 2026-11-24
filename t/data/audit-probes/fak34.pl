my $x=1; my $f=sub { my $o=$x; $x=$_[0]; $o }; my @r=($f->(2),$f->(3),$x); print "@r\n";
