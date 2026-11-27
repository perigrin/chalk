our $x = 1; sub c { $x = 3; 2 } my %h = (a => $x, b => c()); print "$h{a}$h{b}\n";
