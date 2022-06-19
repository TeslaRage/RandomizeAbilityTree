class X2EventListener_RandomizeAbilityTree extends X2EventListener config(RandomizeAbilityTree);

struct SoldierClassAndRow
{
	var name SoldierClass;
    var int Rows;
    var array<int> RanksToKeep;
};

struct AbilityPoolData
{
    var int Rank;
    var int Row;
    var SoldierClassAbilityType Ability;
};

var config bool bLog;
var config array<SoldierClassAndRow> arrAffectedSoldierClasses;

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;

	Templates.AddItem(CreateUnitRankUpListenerTemplate());

	return Templates;
}

static function CHEventListenerTemplate CreateUnitRankUpListenerTemplate()
{
	local CHEventListenerTemplate Template;

	`CREATE_X2TEMPLATE(class'CHEventListenerTemplate', Template, 'RandomizeAbilityTree_UnitRankUp');

	Template.RegisterInStrategy = true;
	
	Template.AddCHEvent('UnitRankUp', RandomizeAbilityTreeUnitRankUpListener, ELD_Immediate);
	return Template;
}

static function EventListenerReturn RandomizeAbilityTreeUnitRankUpListener(Object EventData, Object EventSource, XComGameState NewGameState, Name Event, Object CallbackData)
{
    local XComGameState_Unit UnitState;
    local array<SoldierRankAbilities> AbilityTree;
    local array<AbilityPoolData> AbilityPool;
    local array<SoldierClassAbilityType> AbilityPoolRow, UsedAbilityPoolRow;
    local AbilityPoolData AbilityPoolEntry;
    local SoldierClassAbilityType AbilityToSwapOne, AbilityToSwapTwo;
    local int RankIndex, UnitMaxRank, RankIndexToTake, ConfigIndex, AffectedRows, RowIndex, LoopLimiter, Rand;
    local array<int> RanksToKeep;
    local array<name> ImmovableAbilities;
    local name ImmovableAbilityName;

    UnitState = XComGameState_Unit(EventData);
    if (UnitState == none) return ELR_NoInterrupt;

    // Grab the right unit state
    UnitState = XComGameState_Unit(NewGameState.ModifyStateObject(class'XComGameState_Unit', UnitState.ObjectID));

    // Grab the config applicable for this unit
    ConfigIndex = default.arrAffectedSoldierClasses.Find('SoldierClass', UnitState.GetSoldierClassTemplateName());

    `LOG("UnitState.GetRank(): " $UnitState.GetRank(), default.bLog, 'RandomClassTree');

    // If Unit is available, ranking up to squaddie, and we do have a config for it
    if (UnitState != none && UnitState.GetRank() == 1 &&  ConfigIndex != INDEX_NONE)
    {
        // Grab all the information we need
        AbilityTree = UnitState.AbilityTree;
        UnitMaxRank = UnitState.GetSoldierClassTemplate().GetMaxConfiguredRank();
        AffectedRows = default.arrAffectedSoldierClasses[ConfigIndex].Rows;
        RanksToKeep = default.arrAffectedSoldierClasses[ConfigIndex].RanksToKeep;
        ImmovableAbilities = GetImmovableAbilities(AbilityTree, UnitMaxRank, AffectedRows);

        // RankIndex starts from 1 to skip Squaddie
        // Collect abilities from each rank
        for (RankIndex = 1; RankIndex < UnitMaxRank; RankIndex++)
        {
            // Ranks that should not be touched
            if (RanksToKeep.Find(RankIndex) != INDEX_NONE) continue;

            for (RowIndex = 0; RowIndex < AffectedRows; RowIndex++)
            {
                // If ability should not be moved, then continue the loop
                if (ImmovableAbilities.Find(AbilityTree[RankIndex].Abilities[RowIndex].AbilityName) != INDEX_NONE)
                    continue;

                AbilityPoolEntry.Rank = RankIndex;
                AbilityPoolEntry.Row = RowIndex;
                AbilityPoolEntry.Ability = AbilityTree[RankIndex].Abilities[RowIndex];
                AbilityPool.AddItem(AbilityPoolEntry);
            }
        }

        // Repeat the loops, but this time we start replacing abilities from the pool
        for (RankIndex = 1; RankIndex < UnitMaxRank; RankIndex++)
        {
            // Ranks that should not be touched
            if (RanksToKeep.Find(RankIndex) != INDEX_NONE) continue;

            for (RowIndex = 0; RowIndex < AffectedRows; RowIndex++)
            {
                // If ability should not be moved, then continue the loop
                if (ImmovableAbilities.Find(AbilityTree[RankIndex].Abilities[RowIndex].AbilityName) != INDEX_NONE)
                    continue;

                // Rebuild the pool for the current row but only adding to it abilities we have not used
                AbilityPoolRow.Length = 0;
                foreach AbilityPool(AbilityPoolEntry)
                {
                    if (AbilityPoolEntry.Row == RowIndex && UsedAbilityPoolRow.Find('AbilityName', AbilityPoolEntry.Ability.AbilityName) == INDEX_NONE)
                    {
                        AbilityPoolRow.AddItem(AbilityPoolEntry.Ability);
                    }
                }

                // Once we have the pool, start replacing
                if (AbilityPoolRow.Length > 0)
                {
                    Rand = `SYNC_RAND_STATIC(AbilityPoolRow.Length);
                    AbilityTree[RankIndex].Abilities[RowIndex] = AbilityPoolRow[Rand];
                    UsedAbilityPoolRow.AddItem(AbilityPoolRow[Rand]);
                }
            }
        }
    }

    UnitState.AbilityTree = AbilityTree;

    // if (UnitState != none && UnitState.GetRank() == 1 &&  ConfigIndex != INDEX_NONE)
    // {
    //     AbilityTree = UnitState.AbilityTree;
    //     UnitMaxRank = UnitState.GetSoldierClassTemplate().GetMaxConfiguredRank();

    //     AffectedRows = default.arrAffectedSoldierClasses[ConfigIndex].Rows;
    //     RanksToKeep = default.arrAffectedSoldierClasses[ConfigIndex].RanksToKeep;

    //     ImmovableAbilities = GetImmovableAbilities(AbilityTree, UnitMaxRank, AffectedRows);

    //     foreach ImmovableAbilities(ImmovableAbilityName)
    //     {
    //         `LOG("Immovable: " $ImmovableAbilityName, default.bLog, 'RandomClassTree');
    //     }

    //     // Swapping rank by rank
    //     for (RankIndex = 0; RankIndex < UnitMaxRank; RankIndex++)
    //     {
    //         if (RankIndex == 0) continue; // Skip Squaddie
    //         if (RanksToKeep.Find(RankIndex) != INDEX_NONE) continue; // These are the ones we don't want to touch            

    //         // Swap row by row
    //         for (RowIndex = 0; RowIndex < AffectedRows; RowIndex++)
    //         {
    //             // Determine which rank to swap with                
    //             RankIndexToTake = `SYNC_RAND_STATIC(UnitMaxRank - 1) + 1; // Do a +1 here so we retain squaddie abilities
    //             if (RankIndexToTake >= UnitMaxRank) RankIndexToTake = UnitMaxRank;
    //             `LOG("RankIndexToTake: " $RankIndexToTake, default.bLog, 'RandomClassTree');

    //             // If the rank is forbidden, then we need to re-roll
    //             LoopLimiter = 0;
    //             while (RanksToKeep.Find(RankIndexToTake) != INDEX_NONE || RankIndex == RankIndexToTake)
    //             {
    //                 `LOG("RankIndexToTake is forbidden: " $RankIndexToTake, default.bLog, 'RandomClassTree');
    //                 RankIndexToTake = `SYNC_RAND_STATIC(UnitMaxRank - 1) + 1; // Do a +1 here so we retain squaddie abilities
    //                 if (RankIndexToTake >= UnitMaxRank) RankIndexToTake = UnitMaxRank;
    //                 `LOG("Revised RankIndexToTake: " $RankIndexToTake, default.bLog, 'RandomClassTree');

    //                 // For safety: from testing it has never taken more than 10 tries
    //                 LoopLimiter++;
    //                 if (LoopLimiter >= 10)
    //                 {
    //                     `LOG("LoopLimiter: " $LoopLimiter, default.bLog, 'RandomClassTree');
    //                     RankIndexToTake = RankIndex; // Swaps with itself bahaha
    //                     break;
    //                 }
    //             }

    //             // Some abilities have prereq abilities, so the ability itself, and its prereq will not be moved
    //             if (ImmovableAbilities.Find(AbilityTree[RankIndex].Abilities[RowIndex].AbilityName) != INDEX_NONE || 
    //                 ImmovableAbilities.Find(AbilityTree[RankIndexToTake].Abilities[RowIndex].AbilityName) != INDEX_NONE
    //                 )
    //             {
    //                 `LOG(AbilityTree[RankIndex].Abilities[RowIndex].AbilityName $" is immovable due to PreReqs", default.bLog, 'RandomClassTree');
    //                 continue;
    //             }

    //             // Swap 2 abilities within the same row
    //             AbilityToSwapOne = AbilityTree[RankIndex].Abilities[RowIndex];
    //             AbilityToSwapTwo = AbilityTree[RankIndexToTake].Abilities[RowIndex];
    //             AbilityTree[RankIndex].Abilities[RowIndex] = AbilityToSwapTwo;
    //             AbilityTree[RankIndexToTake].Abilities[RowIndex] = AbilityToSwapOne;

    //             `LOG("Rank" @RankIndex @"Row" @RowIndex @": Swapping" @AbilityToSwapOne.AbilityName @"with" @AbilityToSwapTwo.AbilityName, default.bLog, 'RandomClassTree');
    //         }
    //     }

    //     UnitState.AbilityTree = AbilityTree;
    // }

    return ELR_NoInterrupt;
}

static function array<name> GetImmovableAbilities(array<SoldierRankAbilities> AbilityTree, int UnitMaxRank, int AffectedRows)
{
    local array<name> ImmovableAbilities;
    local int RankIndex, RowIndex;
    local name AbilityName, PrereqAbilityName;
    local X2AbilityTemplateManager AbilityTemplateManager;
    local X2AbilityTemplate AbilityTemplate;
    local bool bHasPrereq;

    AbilityTemplateManager = class'X2AbilityTemplateManager'.static.GetAbilityTemplateManager();

    // Start from Rank 1 because we do not care about Squaddie abilities
    for (RankIndex = 1; RankIndex < UnitMaxRank; RankIndex++)
    {
        for (RowIndex = 0; RowIndex < AffectedRows; RowIndex++)
        {
            AbilityName = AbilityTree[RankIndex].Abilities[RowIndex].AbilityName;            
            AbilityTemplate = AbilityTemplateManager.FindAbilityTemplate(AbilityName);

            if (AbilityTemplate != none)
            {
                bHasPrereq = false;
                foreach AbilityTemplate.PrerequisiteAbilities(PrereqAbilityName)
                {
                    if (InStr(PrereqAbilityName, class'UIArmory_PromotionHero'.default.MutuallyExclusivePrefix, , true) == 0)
                    {
                        // do nothing
                    }
                    else
                    {
                        ImmovableAbilities.AddItem(PrereqAbilityName);
                        bHasPrereq = true;
                    }
                }

                if (bHasPrereq) ImmovableAbilities.AddItem(AbilityName);
            }
        }
    }

    return ImmovableAbilities;
}

// NOT USED
// Wanted to implement a way to randomize in a way that its not possible to get Col skill at Corporal
// But this is practically not appealing without a proper random deck for each row
static function bool IsWithinItsBlock(int RankIndex, int RankIndexToTake)
{
    local int RankDiff;

    RankDiff = RankIndexToTake - RankIndex;
    if (RankDiff < 0) RankDiff *= -1;

    if (RankDiff > 2) return false;

    return true;
}