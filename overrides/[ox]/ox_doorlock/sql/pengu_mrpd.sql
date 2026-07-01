/*
    PenguRP - Mission Row PD doors for ox_doorlock (vanilla MRPD interior).
    Interior doors from sql/default.sql + front entrance from sql/community_mrpd.sql,
    with groups extended to police + bcso + sasp.

    - Front entrance: state 0 (unlocked, public lobby access; LEO can still lock it down).
    - All interior/secure doors: state 1 (locked, only police/bcso/sasp open them).

    Idempotent: re-running deletes the 'mrpd %' rows and re-inserts, so no PK/id collision
    with the existing heist doors (ids 1-6). Apply with:
        mysql -ufivem -p fivem < pengu_mrpd.sql
    then `restart ox_doorlock` in the server console.
*/

DELETE FROM `ox_doorlock` WHERE `name` LIKE 'mrpd %';

INSERT INTO `ox_doorlock` (`name`, `data`) VALUES
    ('mrpd front entrance', '{"coords":{"x":434.7478942871094,"y":-981.916748046875,"z":30.83926963806152},"groups":{"police":0,"bcso":0,"sasp":0},"maxDistance":2.5,"state":0,"doors":[{"coords":{"x":434.7478942871094,"y":-980.618408203125,"z":30.83926963806152},"model":-1215222675,"heading":270},{"coords":{"x":434.7478942871094,"y":-983.215087890625,"z":30.83926963806152},"model":320433149,"heading":270}],"hideUi":false}'),
    ('mrpd locker rooms', '{"maxDistance":2,"heading":90,"coords":{"x":450.1041259765625,"y":-985.7384033203125,"z":30.83930206298828},"groups":{"police":0,"bcso":0,"sasp":0},"state":1,"model":1557126584,"hideUi":false}'),
    ('mrpd cells briefing', '{"maxDistance":2,"coords":{"x":444.7078552246094,"y":-989.4454345703125,"z":30.83930206298828},"doors":[{"model":185711165,"coords":{"x":446.0079345703125,"y":-989.4454345703125,"z":30.83930206298828},"heading":0},{"model":185711165,"coords":{"x":443.40777587890627,"y":-989.4454345703125,"z":30.83930206298828},"heading":180}],"groups":{"police":0,"bcso":0,"sasp":0},"state":1,"hideUi":false}'),
    ('mrpd cell 3', '{"maxDistance":2,"heading":90,"coords":{"x":461.8065185546875,"y":-1001.9515380859375,"z":25.06442832946777},"lockSound":"metal-locker","groups":{"police":0,"bcso":0,"sasp":0},"state":1,"unlockSound":"metallic-creak","model":631614199,"hideUi":false}'),
    ('mrpd back entrance', '{"maxDistance":2,"coords":{"x":468.6697692871094,"y":-1014.4520263671875,"z":26.5362319946289},"doors":[{"model":-2023754432,"coords":{"x":467.37164306640627,"y":-1014.4520263671875,"z":26.5362319946289},"heading":0},{"model":-2023754432,"coords":{"x":469.9678955078125,"y":-1014.4520263671875,"z":26.5362319946289},"heading":180}],"groups":{"police":0,"bcso":0,"sasp":0},"state":1,"hideUi":false}'),
    ('mrpd cells security door', '{"maxDistance":2,"heading":0,"coords":{"x":464.1282958984375,"y":-1003.5386962890625,"z":25.00598907470703},"autolock":5,"groups":{"police":0,"bcso":0,"sasp":0},"state":1,"model":-1033001619,"hideUi":false}'),
    ('mrpd cell 2', '{"maxDistance":2,"heading":90,"coords":{"x":461.8064880371094,"y":-998.3082885742188,"z":25.06442832946777},"lockSound":"metal-locker","groups":{"police":0,"bcso":0,"sasp":0},"state":1,"unlockSound":"metallic-creak","model":631614199,"hideUi":false}'),
    ('mrpd captains office', '{"maxDistance":2,"heading":180,"coords":{"x":446.57281494140627,"y":-980.0105590820313,"z":30.83930206298828},"groups":{"police":0,"bcso":0,"sasp":0},"state":1,"model":-1320876379,"hideUi":false}'),
    ('mrpd gate', '{"maxDistance":6,"heading":90,"coords":{"x":488.894775390625,"y":-1017.2102661132813,"z":27.14714050292968},"groups":{"police":0,"bcso":0,"sasp":0},"auto":true,"state":1,"model":-1603817716,"hideUi":false}'),
    ('mrpd cell 1', '{"maxDistance":2,"heading":270,"coords":{"x":461.8065185546875,"y":-993.7586059570313,"z":25.06442832946777},"lockSound":"metal-locker","groups":{"police":0,"bcso":0,"sasp":0},"state":1,"unlockSound":"metallic-creak","model":631614199,"hideUi":false}'),
    ('mrpd cells main', '{"maxDistance":2,"heading":360,"coords":{"x":463.92010498046877,"y":-992.6640625,"z":25.06442832946777},"lockSound":"metal-locker","groups":{"police":0,"bcso":0,"sasp":0},"state":1,"unlockSound":"metallic-creak","model":631614199,"hideUi":false}'),
    ('mrpd armoury', '{"maxDistance":2,"heading":270,"coords":{"x":453.08428955078127,"y":-982.5794677734375,"z":30.81926536560058},"autolock":5,"groups":{"police":0,"bcso":0,"sasp":0},"state":1,"model":749848321,"hideUi":false}');
