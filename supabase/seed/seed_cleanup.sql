-- يحذف بيانات seed_test_data.sql فقط (الحذف يمتد تلقائيًا إلى الغرف والعضويات والألعاب المرتبطة).
delete from auth.users where email like '%@seed.mafia.invalid';
