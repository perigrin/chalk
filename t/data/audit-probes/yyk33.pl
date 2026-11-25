use feature 'class'; no warnings; class P { field $a :param; field $b = $a * 2; field $c = $a + $b; method s { "$a$b$c" } } print P->new(a => 1)->s, P->new(a => 5)->s, "\n";
