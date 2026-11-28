sub f { return undef } my %h = (a => f(), b => 1); print scalar(keys %h), "\n";
