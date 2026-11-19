my $buf = ""; open(my $out, ">", \$buf); print $out "abc"; my $n1 = length $buf; print $out "de"; my $n2 = length($buf); close $out; print "$n1 $n2\n";
