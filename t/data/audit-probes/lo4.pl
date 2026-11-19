our %h = (a => 1); sub t { local $h{a} = 2; local $h{b} = 3; return join ",", map { "$_$h{$_}" } sort keys %h } print t(), "|", join(",", map { "$_$h{$_}" } sort keys %h), "\n";
