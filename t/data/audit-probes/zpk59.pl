our %c; sub hit { $c{$_[0]}++ } hit("a") for 1..2; hit("b"); print join(",", map { "$_$c{$_}" } sort keys %c), "\n";
