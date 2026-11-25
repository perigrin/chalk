my %h = (a=>1); my %c = %h; $c{a} = 2; $c{b} = 3; my %m = (%h, %c, d => 4); my %e = (); print $h{a}, scalar(keys %c), join("", map { "$_$m{$_}" } sort keys %m), scalar(%e) ? "t" : "f", "\n";
