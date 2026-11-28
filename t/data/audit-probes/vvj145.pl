my %h = (a=>1); sub ch { my %c = @_; $c{a} = 2; %c } my %n = ch(%h); print "$h{a}$n{a}\n";
