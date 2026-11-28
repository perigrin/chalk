our $t = "a"; sub c { $t = 3; 2 } my $s = ($t =~ s/a/b/r) . c(); print "$s\n";
