sub f { return } my %h = (a => f()); print scalar(keys %h), "\n";
