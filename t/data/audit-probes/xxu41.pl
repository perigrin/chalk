our $x = "a"; sub c { $x = "c"; "c" } my $s = ($x eq c()) ? "eq" : "ne"; print "$s\n";
