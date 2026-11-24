sub f { my %o=(v=>1); my %c=%o; $c{v}=2; $o{w}=3; return join ",", $o{v}, (exists $c{w} ? "y" : "n"), $c{v} } print f(), "\n"; print f(), "\n";
