# Chain
Makes SCH skillchains

Reduce immanence skillchaining to a single command to reduce macro sprawl

Use the default skillchain:
Default setting is Fusion
//ch

Use a specific skillchain:
//ch Fragmentation
Fuzzy matching works for skillchain names, "//ch grav" will match Gravitation.

In addition to all 12 normal T1/T2 skillchains, Liqfusion is defined as a 3-step thunder>fire>thunder chain.
//ch lf
//ch 3step
//ch liqfusion

Toggle closing skillchains with helix spells:
Default setting is true
//ch Helix

Toggle replacing helix spells with t1 spells, if the helix is on recast:
Default setting is true
//ch Fallback

The default skillchain and delays after spells and JAs can be adjusted in the settings file, /data/CharName.xml

Many sortie monsters have a custom default chain.
A,C,E,G bosses, Porxie, Bhoot, Deleterious, Botulus, Naraka, and Tulittia default to 3-step Liquefaction > Fusion
Ixion defaults to Gravitation

Wildkeeper mobs default to a skillchain matching their weak element.
