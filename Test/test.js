function fncModifyContentsBoxAndFileList() {
    var chkList = [];
    $('input[name="delete"]:checked').each(function (index) {
       chkList.push($(this).val());
       console.log("chkList >> " + chkList);
       console.log("chkList.length1 >> " + chkList.length);
    });
 
    var param = new Object();
    param.deleteList = [];
    param.description = $("#description").val();
    param.deleteList = chkList;
    console.log("chkList.length2 >> " + chkList.length);
    console.log("param.deleteList.length >> " + param.deleteList.length());