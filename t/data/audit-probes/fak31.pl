my $x=1; my $get=sub { $x }; my $set=sub { $x=$_[0] }; my $a=$get->(); $set->(5); my $b=$get->(); $x=9; print $a,$b,$get->(),"\n";
