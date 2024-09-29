public with sharing class OpportunityTriggerHandler extends TriggerHandler{
    public override void beforeUpdate() {
        Set<Id> accountIds = new Set<Id>();
        for(Opportunity opp : (List<Opportunity>)Trigger.new){
            accountIds.add(opp.AccountId);
            if(opp.Amount < 5000){
                opp.addError('Opportunity amount must be greater than 5000');
            }
        }
        
        Map<Id, Contact> contacts = new Map<Id, Contact>([SELECT Id, FirstName, AccountId FROM Contact WHERE AccountId IN :accountIds AND Title = 'CEO' ORDER BY FirstName ASC]);
        Map<Id, Contact> accountIdToContact = new Map<Id, Contact>();

        for (Contact cont : contacts.values()) {
            if (!accountIdToContact.containsKey(cont.AccountId)) {
                accountIdToContact.put(cont.AccountId, cont);
            }
        }

        for(Opportunity opp : (List<Opportunity>)Trigger.new){
            if(opp.Primary_Contact__c == null && accountIdToContact.containsKey(opp.AccountId)){
                    opp.Primary_Contact__c = accountIdToContact.get(opp.AccountId).Id;
            }
        }
    }

    public override void beforeDelete() {
        Map<Id, Account> accounts = new Map<Id, Account>([SELECT Id, Industry FROM Account WHERE Id IN (SELECT AccountId FROM Opportunity WHERE Id IN :(List<Opportunity>)Trigger.old)]);
        for(Opportunity opp : (List<Opportunity>)Trigger.old){
            if (opp.IsClosed){
                if(opp.StageName == 'Closed Won'){
                    if(accounts.get(opp.AccountId).Industry == 'Banking'){
                        opp.addError('Cannot delete a closed won opportunity for a banking account');
                    }
                }
                opp.addError('Cannot delete closed opportunity');
            }
        }
    }

    public override void beforeInsert() {
        for (Opportunity opp: (List<Opportunity>)Trigger.new) {
            if (opp.Type == null){
                opp.Type = 'New Customer';
            } 
        }
    }

    public override void afterInsert() {
        List<Task> tasksToCreate = new List<Task>();
            for (Opportunity opp : (List<Opportunity>)Trigger.new){
                Task tsk = new Task();
                tsk.Subject = 'Call Primary Contact';
                tsk.WhatId = opp.Id;
                tsk.WhoId = opp.Primary_Contact__c;
                tsk.OwnerId = opp.OwnerId;
                tsk.ActivityDate = Date.today().addDays(3);
                tasksTocreate.add(tsk);
            }
            insert tasksToCreate;
    }

    public override void afterUpdate() {
        Map<Id, Opportunity> oldOppMap = new Map<Id, Opportunity>();
        for (Opportunity opp : (List<Opportunity>)Trigger.old) {
            oldOppMap.put(opp.Id , opp);
        }
            List<Opportunity> updatedOppList = new List<Opportunity>();
            for (Opportunity opp : (List<Opportunity>)Trigger.new){
                Opportunity oldOpp = oldOppMap.get(opp.Id);
                    if (opp.StageName != oldOpp.StageName){
                        Opportunity newOpp = new Opportunity(Id = opp.Id, StageName = opp.StageName);
                        newOpp.Description =  (newOpp.Description == null ? '' : newOpp.Description) + '\n Stage Change:' + newOpp.StageName + ':' + DateTime.now().format();
                        updatedOppList.add(newOpp);
                    }                
            }
            update updatedOppList;
    }

    public override void afterDelete() {
        notifyOwnersOpportunityDeleted((List<Opportunity>)Trigger.old);
    }

    public override void afterUndelete() {
        Map<Id,Opportunity> oppMap = new Map<Id,Opportunity>();
        for (Opportunity opp: (List<Opportunity>)Trigger.new) {
            oppMap.put(opp.Id,opp);
        }
        assignPrimaryContact(oppMap);
    }

    private static void notifyOwnersOpportunityDeleted(List<Opportunity> opps) {
        List<Messaging.SingleEmailMessage> mails = new List<Messaging.SingleEmailMessage>();
        Set<Id> ownerIds = new Set<Id>();
        for (Opportunity opp : opps) {
            ownerIds.add(opp.OwnerId);
        }
        String[] toAddresses = new String[] {[SELECT Id, Email FROM User WHERE Id IN :ownerIds].Email};
        for (Opportunity opp : opps){
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(toAddresses);
            mail.setSubject('Opportunity Deleted : ' + opp.Name);
            mail.setPlainTextBody('Your Opportunity: ' + opp.Name +' has been deleted.');
            mails.add(mail);
        }        
        
        try {
            Messaging.sendEmail(mails);
        } catch (Exception e){
            System.debug('Exception: ' + e.getMessage());
        }
    }

    private static void assignPrimaryContact(Map<Id,Opportunity> oppNewMap) {   
        Set<Id> accountIds = new Set<Id>();
        for (Opportunity opp: oppNewMap.values()) {
            if(opp.AccountId != null) {
                accountIds.add(opp.AccountId);
            }
        }
        Map<Id,Contact> primayContactMap = new Map<Id,Contact>();
        for (Contact con : [SELECT Id, AccountId FROM Contact WHERE Title = 'VP Sales' AND AccountId IN :accountIds]) {
            primayContactMap.put(con.AccountId,con);
        }     
        List<Opportunity> oppsToUpdate = new List<Opportunity>();
        for (Opportunity opp : oppNewMap.values()){            
            if (opp.Primary_Contact__c == null && primayContactMap.containsKey(opp.AccountId)){
                Opportunity oppToUpdate = new Opportunity(Id = opp.Id);
                oppToUpdate.Primary_Contact__c = primayContactMap.get(opp.AccountId).Id;
                oppsToUpdate.add(oppToUpdate);
            }
        }
        update oppsToUpdate;
    }
}