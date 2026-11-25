sub f { my (%o)=@_; join ",", map { "$_=$o{$_}" } sort keys %o } print f(a=>1,b=>2,a=>3), "\n";
