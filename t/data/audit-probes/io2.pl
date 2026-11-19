my $buf = ""; open(my $out, ">", \$buf); print $out "abc"; my $c = $buf; print $out "de"; close $out; print "$c $buf\n";
