our $x = "a"; sub c { $x = "b"; 2 } my %h; $h{$x} = c(); print join(",", %h), "\n";
