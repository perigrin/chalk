my $x = "str"; eval { use strict; my $v = $$x; }; print $@ =~ /strict refs/ ? "strict" : "no", "\n";
