use feature 'class'; no warnings; class P { field $x :param; field $log = ""; ADJUST { $log .= "a$x"; $x *= 2 } ADJUST { $log .= "b$x" } method log { $log } } print P->new(x => 2)->log, "\n";
