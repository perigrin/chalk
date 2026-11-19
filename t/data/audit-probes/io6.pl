my $s = "x\ny\n"; open(my $in, "<", \$s); my $a = <$in>; my $e1 = eof($in) ? 1 : 0; my $b = <$in>; my $e2 = eof($in) ? 1 : 0; print "$e1$e2 $a$b";
