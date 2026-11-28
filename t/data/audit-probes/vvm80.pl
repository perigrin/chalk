our $x = 1; { local $x = 2; $x =~ s/2/5/; print $x } print "$x\n";
