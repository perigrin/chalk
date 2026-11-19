my $str = ""; open(my $fh, ">", \$str) or die; print $fh "x"; my $l1 = length $str; print $fh "y"; close $fh; print "$l1 $str\n";
