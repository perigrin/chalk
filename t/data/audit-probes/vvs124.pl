sub f { return } my %h = (b => 1, a => f()); print scalar(keys %h), exists $h{a} ? "e" : "n", "\n";
