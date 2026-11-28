our $s = "abc"; sub ed { $s =~ s/b/z/; 1 } my $t = $s . ed() . $s; print "$t\n";
