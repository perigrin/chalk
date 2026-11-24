sub f { my %h=@_; my %c=%h; $c{a}++; return "$h{a} $c{a}" } print f(a=>1), "\n";
