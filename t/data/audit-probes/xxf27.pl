our %g = (a=>1); sub rk { join ",", sort keys %g } { local %g = (b=>2); $g{c} = 3; print rk() } print rk(), "\n";
