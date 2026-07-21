# TODO

- Rating distribution with percentile, sliceable by country / worldwide /
  per title.
- Stats amusantes : plus jeune/plus vieux (et/ou le moins de parties) à
  passer la barre des X elo. Basé sur historique `ratings`, pas sur
  l'attribution de titre FIDE donc data fiable (contrairement à "titre le
  plus jeune obtenu", cf. exclu ci-dessous).
- Stats amusantes : plus de parties jouées, all-time + filtrable sur 1 mois /
  12 mois, filtrable par pays au minimum. À voir si intéressant d'ajouter
  d'autres filtres (fédération plus fine, tranche elo...).

# PAGE FEDERATION

Page dédiée par fédération, retrouvable via lien déjà présent dans l'appli
(ex : depuis la fiche pays / drapeau). Layout : cards en haut (une par stat),
top5/10 en dessous, gouverné par des filtres partagés en haut de page.

- Percentile par pays (déjà prévu ci-dessus, à intégrer ici).
- Densité de titres par fédération : ratio titrés/joueurs actifs.
- Doyen actif : raccourci dédié (déjà faisable via most_active/top players,
  mais veut un accès direct sur cette page).
- Biggest riser/faller par pays : à voir si on fait une card custom top5
  dans les deux sens (déjà couvert par `movers.vue` sinon).
- Head-to-head fédérations (comparer distribution elo pays A vs B) : à voir
  plus tard, nécessite plus de travail.

Exclu :
- Titre le plus jeune obtenu : data FIDE peu fiable (process de titre
  ralenti côté FIDE).
- Longévité (années actives) : moyen, liste juste des vieux joueurs.
- Peak rating tracker / comeback stats : déjà trouvable via pages
  existantes.
